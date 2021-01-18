using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class DelayedFade : MonoBehaviour
{
    //Parameters
    [SerializeField] private float _timeToWait = 10.0f;
    [SerializeField] private float _fadeTime = 1.0f;
    [SerializeField] private CanvasGroup _toFade = null;

    //Will start counting down right at the beginning
    private void Start()
    {
        StartCoroutine(FadeAway());
    }

    //Main function
    IEnumerator FadeAway()
    {
        //Invalid? Stop execution
        if(!_toFade) { yield break; }

        //Wait
        _toFade.alpha = 1.0f;
        yield return new WaitForSecondsRealtime(_timeToWait);

        //Fade away
        float alpha = 1.0f;
        while(alpha > 0.0f)
        {
            alpha -= (1.0f / _fadeTime) * Time.unscaledDeltaTime;
            _toFade.alpha = alpha;
            yield return null;
        }

        //Done
        _toFade.alpha = 0.0f;
    }
}
